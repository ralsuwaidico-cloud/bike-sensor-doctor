import Foundation

/// Link 1.3 codec (coord/interfaces/BLE_CONTRACT.md v1, "Cyclift ↔ BikeComputer phone-first contract"): APP_HELLO /
/// HELLO_ACK, COACH_PLAN / PLAN_ACK / STATE / END, the offline ride queue RIDEQ_* (0x90–0x96), STORAGE_* (0xA0–0xA3),
/// DIAG_ACK `03 delete` and EVENT 0x23 rides_pending. Same TLV rules as the rest of BCLink: little-endian, unknown tags
/// skipped, wrong-length known fields skipped, a field running past the end rejects the whole message (`parse` → nil).
///
/// Nothing here is sent unless the board's INFO carries the cap AND its HELLO_ACK enabled it on this connection
/// (`Link13Session`). A 0.7.3 board (no cap 0x0800) never receives a single Link 1.3 byte.
extension BCLink {
    static let link13Major: UInt8 = 1
    static let link13Minor: UInt8 = 3
    /// What this Cyclift build implements (APP_HELLO `03 app_caps`). Same bit values as INFO caps.
    static let appCaps13: UInt32 = Info.capHello | Info.capCoach | Info.capRideQueue | Info.capStorage | Info.capDiagAuto

    /// UTF-8 prefix of at most `max` bytes, cut at a character boundary (never half a multi-byte character).
    static func utf8Prefix(_ s: String, max: Int) -> Data {
        var out = Data()
        for ch in s {
            let b = Data(String(ch).utf8)
            if out.count + b.count > max { break }
            out.append(b)
        }
        return out
    }

    /// Header + TLVs with no size cap (test helpers that mirror the board, and size checks).
    static func rawMessage(_ type: MsgType, seq: UInt16, tMs: UInt32, _ fields: [(UInt8, Data)]) -> Data {
        var d = Data([type.rawValue, 0]); d.append(le(seq)); d.append(le(tMs))
        for (t, v) in fields { d.append(t); d.append(UInt8(v.count)); d.append(v) }
        return d
    }

    // MARK: §4 APP_HELLO 0x08 / HELLO_ACK 0x09
    static func encodeAppHello(appCaps: UInt32 = appCaps13, appVersion: String, seq: UInt16, tMs: UInt32) -> Data? {
        var w = Writer(type: .appHello, seq: seq, tMs: tMs)
        w.u8(0x01, link13Major); w.u8(0x02, link13Minor); w.u32(0x03, appCaps); w.field(0x04, utf8Prefix(appVersion, max: 16))
        return w.result
    }
    struct HelloAck: Equatable { var enabledCaps: UInt32 = 0 }
    /// nil unless it is a HELLO_ACK carrying `01 enabled_caps`.
    static func decodeHelloAck(_ d: Data) -> HelloAck? {
        guard let (h, f) = parse(d), h.type == MsgType.helloAck.rawValue else { return nil }
        var a = HelloAck(); var got = false
        for x in f where x.tag == 0x01 && x.value.count == 4 { a.enabledCaps = UInt32(uint(x.value)); got = true }
        return got ? a : nil
    }
    static func encodeHelloAck(enabledCaps: UInt32, seq: UInt16, tMs: UInt32) -> Data { rawMessage(.helloAck, seq: seq, tMs: tMs, [(0x01, le(enabledCaps))]) }

    // MARK: §5 coach mirroring
    /// §5.1 enumerations (wire values).
    enum CoachWorkoutType: UInt8, CaseIterable {
        case freeRide = 0, recovery = 1, endurance = 2, tempo = 3, sweetSpot = 4, threshold = 5, vo2max = 6, anaerobic = 7, sprint = 8
        case ftpTest = 9, race = 10, warmUp = 11, coolDown = 12, custom = 13
        /// The words the board prints (≤ 12 chars, round screen).
        var label: String {
            switch self {
            case .freeRide: return "FREE RIDE"; case .recovery: return "RECOVERY"; case .endurance: return "ENDURANCE"; case .tempo: return "TEMPO"
            case .sweetSpot: return "SWEET SPOT"; case .threshold: return "THRESHOLD"; case .vo2max: return "VO2MAX"; case .anaerobic: return "ANAEROBIC"
            case .sprint: return "SPRINT"; case .ftpTest: return "FTP TEST"; case .race: return "RACE"; case .warmUp: return "WARM-UP"; case .coolDown: return "COOL-DOWN"; case .custom: return "CUSTOM"
            }
        }
    }
    enum CoachTargetKind: UInt8 { case none = 0, powerW = 1, heartRateBpm = 2, cadenceOnly = 3, rpe = 4 }
    enum CoachInstruction: UInt8, CaseIterable {
        case none = 0, onTarget = 1, morePower = 2, lessPower = 3, cadenceUp = 4, cadenceDown = 5, holdSteady = 6, getReady = 7, easyRecover = 8
        case go = 9, coolDown = 10, hrHighEaseOff = 11, drinkFuel = 12, paused = 13, workoutDone = 14, noData = 15, targetChanged = 16
        /// The board's fixed text (≤ 24 chars) — shown identically on the phone preview.
        var text: String {
            switch self {
            case .none: return ""; case .onTarget: return "ON TARGET"; case .morePower: return "MORE POWER"; case .lessPower: return "LESS POWER"
            case .cadenceUp: return "CADENCE UP"; case .cadenceDown: return "CADENCE DOWN"; case .holdSteady: return "HOLD STEADY"; case .getReady: return "GET READY"
            case .easyRecover: return "EASY / RECOVER"; case .go: return "GO!"; case .coolDown: return "COOL DOWN"; case .hrHighEaseOff: return "HR HIGH - EASE OFF"
            case .drinkFuel: return "DRINK / FUEL"; case .paused: return "PAUSED"; case .workoutDone: return "WORKOUT DONE"; case .noData: return "NO DATA"; case .targetChanged: return "TARGET CHANGED"
            }
        }
    }
    enum CoachSessionState: UInt8 { case notStarted = 0, running = 1, paused = 2, finished = 3, abandoned = 4 }
    /// Board timeline value meaning "segment 0 starts when the ride starts" (§5.2 tag 0A).
    static let coachT0AtRideStart: UInt32 = 0xFFFF_FFFF
    /// Segments per message: ≤ 9 in part 0 (it also carries name, totals, crc, t0), ≤ 14 in later parts (§5.2).
    static let coachSegmentsPart0 = 9, coachSegmentsPerPart = 14, coachMaxSegments = 64

    /// One plan segment, 10 bytes on the wire: `u16 duration_s` `u8 workout_type` `u8 target_kind` `u16 lo` `u16 hi`
    /// `u8 cad_lo` `u8 cad_hi` (0 = no cadence target).
    struct CoachSegment: Equatable {
        var durationS: UInt16
        var type: CoachWorkoutType
        var targetKind: CoachTargetKind
        var lo: UInt16
        var hi: UInt16
        var cadLo: UInt8
        var cadHi: UInt8
        var bytes: Data {
            var d = le(durationS); d.append(type.rawValue); d.append(targetKind.rawValue); d.append(le(lo)); d.append(le(hi)); d.append(cadLo); d.append(cadHi)
            return d
        }
        static func decode(_ d: Data) -> CoachSegment? {
            guard d.count == 10 else { return nil }
            let b = [UInt8](d)
            return CoachSegment(durationS: UInt16(b[0]) | UInt16(b[1]) << 8, type: CoachWorkoutType(rawValue: b[2]) ?? .custom,
                                targetKind: CoachTargetKind(rawValue: b[3]) ?? .none, lo: UInt16(b[4]) | UInt16(b[5]) << 8,
                                hi: UInt16(b[6]) | UInt16(b[7]) << 8, cadLo: b[8], cadHi: b[9])
        }
    }
    /// The whole authoritative workout definition (phone side).
    struct CoachPlan: Equatable {
        var workoutId: UInt32
        var name: String
        var segments: [CoachSegment]
        /// Board `elapsed_s` at which segment 0 starts; `coachT0AtRideStart` = when the ride starts.
        var t0ElapsedS: UInt32
        var totalDurationS: UInt32 { segments.reduce(0) { $0 + UInt32($1.durationS) } }
        var segmentBytes: Data { segments.reduce(into: Data()) { $0.append($1.bytes) } }
        /// CRC-32/ISO-HDLC (= zlib crc32) of all segment bytes in order (§5.2 tag 09).
        var crc32: UInt32 { CRC32.ieee(segmentBytes) }
        var partCount: Int { segments.count <= coachSegmentsPart0 ? 1 : 1 + (segments.count - coachSegmentsPart0 + coachSegmentsPerPart - 1) / coachSegmentsPerPart }
        /// First segment index and count carried by `part`.
        func range(ofPart part: Int) -> Range<Int> {
            let start = part == 0 ? 0 : coachSegmentsPart0 + (part - 1) * coachSegmentsPerPart
            let n = part == 0 ? coachSegmentsPart0 : coachSegmentsPerPart
            return min(start, segments.count)..<min(start + n, segments.count)
        }
    }

    /// COACH_PLAN 0xB0, one part. nil for an invalid plan (no segments, > 64 segments) or a part out of range.
    static func encodeCoachPlan(_ p: CoachPlan, part: Int, seq: UInt16, tMs: UInt32) -> Data? {
        guard !p.segments.isEmpty, p.segments.count <= coachMaxSegments, part >= 0, part < p.partCount else { return nil }
        let r = p.range(ofPart: part)
        var w = Writer(type: .coachPlan, seq: seq, tMs: tMs)
        w.u32(0x01, p.workoutId); w.u16(0x02, UInt16(part)); w.u16(0x03, UInt16(p.partCount)); w.u16(0x04, UInt16(r.lowerBound))
        w.field(0x05, p.segments[r].reduce(into: Data()) { $0.append($1.bytes) })
        if part == 0 {
            w.field(0x06, utf8Prefix(p.name, max: 20)); w.u16(0x07, UInt16(p.segments.count)); w.u32(0x08, p.totalDurationS)
            w.u32(0x09, p.crc32); w.u32(0x0A, p.t0ElapsedS)
        }
        return w.result
    }
    /// What a board parses from one COACH_PLAN part (test helper mirroring the firmware parser, and fixture checks).
    struct CoachPlanPart: Equatable {
        var workoutId: UInt32 = 0, part = 0, parts = 0, firstSegment = 0
        var segments: [CoachSegment] = []
        var name: String? = nil, totalSegments: Int? = nil, totalDurationS: UInt32? = nil, crc32: UInt32? = nil, t0ElapsedS: UInt32? = nil
    }
    static func decodeCoachPlan(_ d: Data) -> CoachPlanPart? {
        guard let (h, f) = parse(d), h.type == MsgType.coachPlan.rawValue else { return nil }
        var p = CoachPlanPart(); var gotId = false, gotSeg = false
        for x in f {
            let v = x.value
            switch (x.tag, v.count) {
            case (0x01, 4): p.workoutId = UInt32(uint(v)); gotId = true
            case (0x02, 2): p.part = Int(uint(v))
            case (0x03, 2): p.parts = Int(uint(v))
            case (0x04, 2): p.firstSegment = Int(uint(v))
            case (0x05, let n) where n % 10 == 0:
                p.segments = stride(from: 0, to: n, by: 10).compactMap { CoachSegment.decode(v.subdata(in: (v.startIndex + $0)..<(v.startIndex + $0 + 10))) }; gotSeg = true
            case (0x06, 0...20): p.name = String(decoding: v, as: UTF8.self)
            case (0x07, 2): p.totalSegments = Int(uint(v))
            case (0x08, 4): p.totalDurationS = UInt32(uint(v))
            case (0x09, 4): p.crc32 = UInt32(uint(v))
            case (0x0A, 4): p.t0ElapsedS = UInt32(uint(v))
            default: break
            }
        }
        return gotId && gotSeg ? p : nil
    }

    /// COACH_PLAN_ACK 0xB1: `01 u32 workout_id` `02 u8 status` `03 u16 next_part`.
    struct CoachPlanAck: Equatable {
        enum Status: UInt8 { case stored = 0, partReceived = 1, tooManySegments = 2, crcMismatch = 3, busy = 4 }
        var workoutId: UInt32 = 0; var statusRaw: UInt8 = 0; var nextPart = 0
        var status: Status? { Status(rawValue: statusRaw) }
    }
    static func decodeCoachPlanAck(_ d: Data) -> CoachPlanAck? {
        guard let (h, f) = parse(d), h.type == MsgType.coachPlanAck.rawValue else { return nil }
        var a = CoachPlanAck(); var gotId = false, gotStatus = false
        for x in f {
            switch (x.tag, x.value.count) {
            case (0x01, 4): a.workoutId = UInt32(uint(x.value)); gotId = true
            case (0x02, 1): a.statusRaw = x.value[x.value.startIndex]; gotStatus = true
            case (0x03, 2): a.nextPart = Int(uint(x.value))
            default: break
            }
        }
        return gotId && gotStatus ? a : nil
    }
    static func encodeCoachPlanAck(_ a: CoachPlanAck, seq: UInt16, tMs: UInt32) -> Data {
        rawMessage(.coachPlanAck, seq: seq, tMs: tMs, [(0x01, le(a.workoutId)), (0x02, Data([a.statusRaw])), (0x03, le(UInt16(a.nextPart)))])
    }

    /// COACH_STATE 0xB2 — the live coach as the phone sees it (§5.3).
    struct CoachState: Equatable {
        var workoutId: UInt32 = 0
        var seq: UInt16 = 0
        var type: CoachWorkoutType = .freeRide
        var targetKind: CoachTargetKind = .none
        var targetLo: UInt16 = 0, targetHi: UInt16 = 0
        var cadLo: UInt8 = 0, cadHi: UInt8 = 0
        var intervalIndex: UInt16 = 0, intervalCount: UInt16 = 0
        var remainingS: UInt16 = 0, intervalDurationS: UInt16 = 0
        /// nil = no next interval (last segment): the next_* tags are left out.
        var nextType: CoachWorkoutType? = nil
        var nextTargetKind: CoachTargetKind = .none
        var nextLo: UInt16 = 0, nextHi: UInt16 = 0, nextDurationS: UInt16 = 0
        var instruction: CoachInstruction = .none
        /// ≤ 24 bytes UTF-8, cut at a character boundary; empty = tag left out.
        var text = ""
        var sessionState: CoachSessionState = .notStarted
        /// bc_src_t of the heart rate the phone's coach used (2 board strap, 4 Apple Watch via phone, 6 phone strap, 0 none).
        var hrSource: UInt8 = 0
        var zone: UInt8 = 0
        /// bit0 targets changed by adaptation now, bit1 targets %FTP-derived, bit2 Apple Watch HR live on the phone.
        var flags: UInt8 = 0
        static let flagAdapted: UInt8 = 0x01, flagFtpDerived: UInt8 = 0x02, flagWatchHRLive: UInt8 = 0x04
        /// Everything but `seq` (a resend of the same content keeps its seq).
        func sameContent(_ o: CoachState) -> Bool { var a = self, b = o; a.seq = 0; b.seq = 0; return a == b }
    }
    static func encodeCoachState(_ s: CoachState, seq: UInt16, tMs: UInt32) -> Data? {
        var w = Writer(type: .coachState, seq: seq, tMs: tMs)
        w.u32(0x01, s.workoutId); w.u16(0x02, s.seq); w.u8(0x03, s.type.rawValue); w.u8(0x04, s.targetKind.rawValue)
        w.u16(0x05, s.targetLo); w.u16(0x06, s.targetHi); w.u8(0x07, s.cadLo); w.u8(0x08, s.cadHi)
        w.u16(0x09, s.intervalIndex); w.u16(0x0A, s.intervalCount); w.u16(0x0B, s.remainingS); w.u16(0x0C, s.intervalDurationS)
        // v1.3 merge: EVERY field is sent every time (an omitted one would keep a stale value on the board) — no next
        // interval is sent as next_type 0xFF, no text as an empty text
        if let n = s.nextType {
            w.u8(0x0D, n.rawValue); w.u8(0x0E, s.nextTargetKind.rawValue); w.u16(0x0F, s.nextLo); w.u16(0x10, s.nextHi); w.u16(0x11, s.nextDurationS)
        } else {
            w.u8(0x0D, coachNoNextType); w.u8(0x0E, 0); w.u16(0x0F, 0); w.u16(0x10, 0); w.u16(0x11, 0)
        }
        w.u8(0x12, s.instruction.rawValue)
        w.field(0x13, utf8Prefix(s.text, max: 24))
        w.u8(0x14, s.sessionState.rawValue); w.u8(0x15, s.hrSource); w.u8(0x16, s.zone); w.u8(0x17, s.flags)
        return w.result
    }
    /// Test helper mirroring the firmware parser.
    static func decodeCoachState(_ d: Data) -> CoachState? {
        guard let (h, f) = parse(d), h.type == MsgType.coachState.rawValue else { return nil }
        var s = CoachState(); var gotId = false, gotSeq = false
        for x in f {
            let v = x.value
            func b() -> UInt8 { v[v.startIndex] }
            func w() -> UInt16 { UInt16(uint(v)) }
            switch (x.tag, v.count) {
            case (0x01, 4): s.workoutId = UInt32(uint(v)); gotId = true
            case (0x02, 2): s.seq = w(); gotSeq = true
            case (0x03, 1): s.type = CoachWorkoutType(rawValue: b()) ?? .custom
            case (0x04, 1): s.targetKind = CoachTargetKind(rawValue: b()) ?? .none
            case (0x05, 2): s.targetLo = w()
            case (0x06, 2): s.targetHi = w()
            case (0x07, 1): s.cadLo = b()
            case (0x08, 1): s.cadHi = b()
            case (0x09, 2): s.intervalIndex = w()
            case (0x0A, 2): s.intervalCount = w()
            case (0x0B, 2): s.remainingS = w()
            case (0x0C, 2): s.intervalDurationS = w()
            case (0x0D, 1): s.nextType = b() == coachNoNextType ? nil : (CoachWorkoutType(rawValue: b()) ?? .custom)
            case (0x0E, 1): s.nextTargetKind = CoachTargetKind(rawValue: b()) ?? .none
            case (0x0F, 2): s.nextLo = w()
            case (0x10, 2): s.nextHi = w()
            case (0x11, 2): s.nextDurationS = w()
            case (0x12, 1): s.instruction = CoachInstruction(rawValue: b()) ?? .none
            case (0x13, 0...24): s.text = String(decoding: v, as: UTF8.self)
            case (0x14, 1): s.sessionState = CoachSessionState(rawValue: b()) ?? .notStarted
            case (0x15, 1): s.hrSource = b()
            case (0x16, 1): s.zone = b()
            case (0x17, 1): s.flags = b()
            default: break
            }
        }
        return gotId && gotSeq ? s : nil
    }

    /// v1.3 keepalive: `01 workout_id` + `02 seq` only — refreshes the board's 12 s freshness, changes nothing else.
    static func encodeCoachKeepalive(workoutId: UInt32, stateSeq: UInt16, seq: UInt16, tMs: UInt32) -> Data? {
        var w = Writer(type: .coachState, seq: seq, tMs: tMs); w.u32(0x01, workoutId); w.u16(0x02, stateSeq); return w.result
    }
    /// "No next interval" (last segment). v1.3 merges COACH_STATE, so an omitted next_* would keep the previous NEXT on the
    /// board; Cyclift therefore always sends the next tags and uses this value for "none" (contract question Q-iOS-15).
    static let coachNoNextType: UInt8 = 0xFF

    enum CoachEndReason: UInt8 { case completed = 0, stoppedByRider = 1, replaced = 2 }
    static func encodeCoachEnd(workoutId: UInt32, reason: CoachEndReason, seq: UInt16, tMs: UInt32) -> Data? {
        var w = Writer(type: .coachEnd, seq: seq, tMs: tMs); w.u32(0x01, workoutId); w.u8(0x02, reason.rawValue); return w.result
    }

    // MARK: §6 offline ride queue
    enum RideQueueState: UInt8 { case recording = 0, closedUnsynced = 1, transferring = 2, verifiedOnPhone = 3, samplesDeleted = 4
        var words: String {
            switch self {
            case .recording: return "recording"; case .closedUnsynced: return "waiting for Cyclift"; case .transferring: return "transfer in progress"
            case .verifiedOnPhone: return "saved in Cyclift"; case .samplesDeleted: return "saved in Cyclift (removed from the board)"
            }
        }
    }
    /// RIDEQ_INFO 0x91.
    struct RideQueueInfo: Equatable {
        var rideId: UInt32 = 0
        var stateRaw: UInt8 = 0
        var samplesSize: UInt32 = 0
        var samplesCrc32: UInt32 = 0
        var startEpochS: UInt32 = 0          /* 0 = unknown */
        var durationS: UInt32 = 0
        /// bit0 reserved (v1.1: demo rides are never listed), bit1 recovered after a crash, bit2 samples truncated, bit3 summary
        /// only, bit4 RAM only (board storage damaged: the summary is held in RAM until power-off, no samples)
        var flags: UInt8 = 0
        var summaryCrc32: UInt32 = 0
        var state: RideQueueState? { RideQueueState(rawValue: stateRaw) }
        var demo: Bool { flags & 0x01 != 0 }
        var recovered: Bool { flags & 0x02 != 0 }
        var truncated: Bool { flags & 0x04 != 0 }
        var summaryOnly: Bool { flags & 0x08 != 0 }
        /// At risk: lost if the BikeComputer powers off before Cyclift saves it.
        var ramOnly: Bool { flags & 0x10 != 0 }
        /// The board still holds it as unsynced (closed or mid-transfer): Cyclift must import it.
        var needsImport: Bool { state == .closedUnsynced || state == .transferring }
    }
    struct RideQueueListEnd: Equatable { var count = 0; var unsynced = 0; var unsyncedBytes: UInt32 = 0 }
    struct RideQueueChunk: Equatable { var rideId: UInt32 = 0; var offset: UInt32 = 0; var data = Data(); var last = false }
    /// RIDEQ_ERR codes = DIAG_ERR codes (§6).
    typealias RideQueueErr = DiagErr
    struct RidesPending: Equatable { var unsynced = 0; var newestRideId: UInt32 = 0 }
    static let ridesPendingEventId = 0x23

    static func encodeRideQueueListRequest(seq: UInt16, tMs: UInt32) -> Data? { Writer(type: .rideqListReq, seq: seq, tMs: tMs).result }
    /// Byte-identical layout to DIAG_CHUNK_REQ (§6): `max_len` from `diagRequestMaxLen(linkPayload:)`.
    static func encodeRideQueueChunkRequest(rideId: UInt32, offset: UInt32, maxLen: UInt16, seq: UInt16, tMs: UInt32) -> Data? {
        var w = Writer(type: .rideqChunkReq, seq: seq, tMs: tMs)
        w.u32(0x01, rideId); w.u32(0x02, offset); w.u16(0x03, maxLen)
        return w.result
    }
    static func encodeRideQueueAck(rideId: UInt32, samplesCrc32: UInt32, summaryCrc32: UInt32, deleteSamples: Bool, seq: UInt16, tMs: UInt32) -> Data? {
        var w = Writer(type: .rideqAck, seq: seq, tMs: tMs)
        w.u32(0x01, rideId); w.u32(0x02, samplesCrc32); w.u32(0x03, summaryCrc32); w.u8(0x04, deleteSamples ? 1 : 0)
        return w.result
    }
    /// nil unless it carries ride_id, state, samples_size and samples_crc32.
    static func decodeRideQueueInfo(_ d: Data) -> RideQueueInfo? {
        guard let (h, f) = parse(d), h.type == MsgType.rideqInfo.rawValue else { return nil }
        var i = RideQueueInfo(); var gotId = false, gotState = false, gotSize = false, gotCrc = false
        for x in f {
            let v = x.value
            switch (x.tag, v.count) {
            case (0x01, 4): i.rideId = UInt32(uint(v)); gotId = true
            case (0x02, 1): i.stateRaw = v[v.startIndex]; gotState = true
            case (0x03, 4): i.samplesSize = UInt32(uint(v)); gotSize = true
            case (0x04, 4): i.samplesCrc32 = UInt32(uint(v)); gotCrc = true
            case (0x05, 4): i.startEpochS = UInt32(uint(v))
            case (0x06, 4): i.durationS = UInt32(uint(v))
            case (0x07, 1): i.flags = v[v.startIndex]
            case (0x08, 4): i.summaryCrc32 = UInt32(uint(v))
            default: break
            }
        }
        return gotId && gotState && gotSize && gotCrc ? i : nil
    }
    static func decodeRideQueueListEnd(_ d: Data) -> RideQueueListEnd? {
        guard let (h, f) = parse(d), h.type == MsgType.rideqListEnd.rawValue else { return nil }
        var e = RideQueueListEnd()
        for x in f {
            switch (x.tag, x.value.count) {
            case (0x01, 2): e.count = Int(uint(x.value))
            case (0x02, 2): e.unsynced = Int(uint(x.value))
            case (0x03, 4): e.unsyncedBytes = UInt32(uint(x.value))
            default: break
            }
        }
        return e
    }
    static func decodeRideQueueChunk(_ d: Data) -> RideQueueChunk? {
        guard let (h, f) = parse(d), h.type == MsgType.rideqChunk.rawValue else { return nil }
        var c = RideQueueChunk(); var gotId = false, gotOff = false, gotData = false
        for x in f {
            let v = x.value
            switch (x.tag, v.count) {
            case (0x01, 4): c.rideId = UInt32(uint(v)); gotId = true
            case (0x02, 4): c.offset = UInt32(uint(v)); gotOff = true
            case (0x03, _): c.data = Data(v); gotData = true
            case (0x04, 1): c.last = v[v.startIndex] != 0
            default: break
            }
        }
        return gotId && gotOff && gotData ? c : nil
    }
    static func decodeRideQueueErr(_ d: Data) -> RideQueueErr? {
        guard let (h, f) = parse(d), h.type == MsgType.rideqErr.rawValue else { return nil }
        var e = RideQueueErr(); var gotCode = false
        for x in f { switch (x.tag, x.value.count) { case (0x01, 4): e.reportId = UInt32(uint(x.value)); case (0x02, 1): e.code = x.value[x.value.startIndex]; gotCode = true; default: break } }
        return gotCode ? e : nil
    }
    /// EVENT 0x40 with event_id 0x23 (`02 u8 unsynced` `03 u32 newest ride_id`); nil for every other event.
    static func decodeRidesPending(_ d: Data) -> RidesPending? {
        guard let (h, f) = parse(d), h.type == MsgType.event.rawValue else { return nil }
        var r = RidesPending(); var isIt = false
        for x in f {
            switch (x.tag, x.value.count) {
            case (0x01, 1): isIt = Int(x.value[x.value.startIndex]) == ridesPendingEventId
            case (0x02, 1): r.unsynced = Int(x.value[x.value.startIndex])
            case (0x03, 4): r.newestRideId = UInt32(uint(x.value))
            default: break
            }
        }
        return isIt ? r : nil
    }
    // test helpers mirroring the board encoders (tag order = contract table)
    static func encodeRideQueueInfo(_ i: RideQueueInfo, seq: UInt16, tMs: UInt32) -> Data {
        rawMessage(.rideqInfo, seq: seq, tMs: tMs, [(0x01, le(i.rideId)), (0x02, Data([i.stateRaw])), (0x03, le(i.samplesSize)), (0x04, le(i.samplesCrc32)),
                                                    (0x05, le(i.startEpochS)), (0x06, le(i.durationS)), (0x07, Data([i.flags])), (0x08, le(i.summaryCrc32))])
    }
    static func encodeRideQueueListEnd(_ e: RideQueueListEnd, seq: UInt16, tMs: UInt32) -> Data {
        rawMessage(.rideqListEnd, seq: seq, tMs: tMs, [(0x01, le(UInt16(e.count))), (0x02, le(UInt16(e.unsynced))), (0x03, le(e.unsyncedBytes))])
    }
    static func encodeRideQueueChunk(_ c: RideQueueChunk, seq: UInt16, tMs: UInt32) -> Data {
        rawMessage(.rideqChunk, seq: seq, tMs: tMs, [(0x01, le(c.rideId)), (0x02, le(c.offset)), (0x03, c.data), (0x04, Data([c.last ? 1 : 0]))])
    }
    static func encodeRideQueueErr(rideId: UInt32, code: UInt8, seq: UInt16, tMs: UInt32) -> Data {
        rawMessage(.rideqErr, seq: seq, tMs: tMs, [(0x01, le(rideId)), (0x02, Data([code]))])
    }
    static func encodeRidesPending(unsynced: UInt8, newest: UInt32, seq: UInt16, tMs: UInt32) -> Data {
        rawMessage(.event, seq: seq, tMs: tMs, [(0x01, Data([UInt8(ridesPendingEventId)])), (0x02, Data([unsynced])), (0x03, le(newest))])
    }

    /// v1.3 SYNC_REQ with `03 u16 only_ride_id`: a board ≥ 0.7.4-rc4 answers exactly that ride's SYNC_RIDE (or nothing) and
    /// releases nothing; an older board ignores tag 03 and answers the after/max part (`after = id − 1, max 1`).
    static func encodeSyncRequest(onlyRideId id: UInt32, seq: UInt16, tMs: UInt32) -> Data? {
        var w = Writer(type: .syncReq, seq: seq, tMs: tMs)
        w.u16(0x01, UInt16(clamping: max(0, Int(id) - 1))); w.u8(0x02, 1); w.u16(0x03, UInt16(clamping: id))
        return w.result
    }

    // MARK: §7 storage status and safe cleanup
    /// bc_stor_state_t (§7 tag 01).
    enum StorageState: UInt8, CaseIterable {
        case ok = 0, full = 1, fsUnavailable = 2, dirCorrupted = 3, writeFailed = 4, diagUnavailable = 5, reportsFull = 6, notChecked = 7
        var title: String {
            switch self {
            case .ok: return "OK"; case .full: return "Storage full"; case .fsUnavailable: return "Filesystem unavailable"; case .dirCorrupted: return "Directory corrupted"
            case .writeFailed: return "Write failed"; case .diagUnavailable: return "Diagnostics unavailable"; case .reportsFull: return "Reports full (unsent)"; case .notChecked: return "Not checked yet"
            }
        }
    }
    struct StorageStatus: Equatable {
        var stateRaw: UInt8 = 7
        var code = ""
        var fsTotalKB: UInt32? = nil, fsFreeKB: UInt32? = nil
        /// 0 missing, 1 empty, 2 dump stored, 3 dump unreadable
        var crashPartition: UInt8? = nil
        var crashDumpBytes: UInt32? = nil
        var reportsStored: Int? = nil, reportsUnsent: Int? = nil
        var diagBytes: UInt32? = nil
        var ridesUnsynced: Int? = nil
        var rideBytesUnsynced: UInt32? = nil, rideBytesSynced: UInt32? = nil
        var appSlotKB: UInt32? = nil, appUsedKB: UInt32? = nil
        var nvsUsedEntries: Int? = nil, nvsFreeEntries: Int? = nil
        var rootFreeSlots: Int? = nil, rootBadEntries: Int? = nil
        /// 0 good, 1 degraded, 2 failed
        var healthRaw: UInt8? = nil
        var state: StorageState? { StorageState(rawValue: stateRaw) }
    }
    static func encodeStorageStatusRequest(seq: UInt16, tMs: UInt32) -> Data? { Writer(type: .storageStatusReq, seq: seq, tMs: tMs).result }
    static func decodeStorageStatus(_ d: Data) -> StorageStatus? {
        guard let (h, f) = parse(d), h.type == MsgType.storageStatus.rawValue else { return nil }
        var s = StorageStatus(); var gotState = false
        for x in f {
            let v = x.value
            func u32() -> UInt32 { UInt32(uint(v)) }
            func u16() -> Int { Int(uint(v)) }
            switch (x.tag, v.count) {
            case (0x01, 1): s.stateRaw = v[v.startIndex]; gotState = true
            case (0x02, 0...16): s.code = String(decoding: v, as: UTF8.self)
            case (0x03, 4): s.fsTotalKB = u32()
            case (0x04, 4): s.fsFreeKB = u32()
            case (0x05, 1): s.crashPartition = v[v.startIndex]
            case (0x06, 4): s.crashDumpBytes = u32()
            case (0x07, 2): s.reportsStored = u16()
            case (0x08, 2): s.reportsUnsent = u16()
            case (0x09, 4): s.diagBytes = u32()
            case (0x0A, 2): s.ridesUnsynced = u16()
            case (0x0B, 4): s.rideBytesUnsynced = u32()
            case (0x0C, 4): s.rideBytesSynced = u32()
            case (0x0D, 4): s.appSlotKB = u32()
            case (0x0E, 4): s.appUsedKB = u32()
            case (0x0F, 2): s.nvsUsedEntries = u16()
            case (0x10, 2): s.nvsFreeEntries = u16()
            case (0x11, 2): s.rootFreeSlots = u16()
            case (0x12, 2): s.rootBadEntries = u16()
            case (0x13, 1): s.healthRaw = v[v.startIndex]
            default: break
            }
        }
        return gotState ? s : nil
    }
    /// Test helper mirroring the board's STORAGE_STATUS (only the fields that are set, contract tag order).
    static func encodeStorageStatus(_ s: StorageStatus, seq: UInt16, tMs: UInt32) -> Data {
        var f: [(UInt8, Data)] = [(0x01, Data([s.stateRaw])), (0x02, Data(s.code.utf8.prefix(16)))]
        func add32(_ t: UInt8, _ v: UInt32?) { if let v { f.append((t, le(v))) } }
        func add16(_ t: UInt8, _ v: Int?) { if let v { f.append((t, le(UInt16(clamping: v)))) } }
        add32(0x03, s.fsTotalKB); add32(0x04, s.fsFreeKB)
        if let c = s.crashPartition { f.append((0x05, Data([c]))) }
        add32(0x06, s.crashDumpBytes); add16(0x07, s.reportsStored); add16(0x08, s.reportsUnsent); add32(0x09, s.diagBytes)
        add16(0x0A, s.ridesUnsynced); add32(0x0B, s.rideBytesUnsynced); add32(0x0C, s.rideBytesSynced); add32(0x0D, s.appSlotKB); add32(0x0E, s.appUsedKB)
        add16(0x0F, s.nvsUsedEntries); add16(0x10, s.nvsFreeEntries); add16(0x11, s.rootFreeSlots); add16(0x12, s.rootBadEntries)
        if let hh = s.healthRaw { f.append((0x13, Data([hh]))) }
        return rawMessage(.storageStatus, seq: seq, tMs: tMs, f)
    }

    /// STORAGE_CLEAN_REQ `01 u8 what`.
    struct StorageCleanWhat: OptionSet, Equatable {
        let rawValue: UInt8
        static let ackedReports = StorageCleanWhat(rawValue: 0x01)     /* ACKed reports + their core copies */
        static let syncedRideSamples = StorageCleanWhat(rawValue: 0x02)/* samples of verified rides */
        static let caches = StorageCleanWhat(rawValue: 0x04)           /* caches / duplicates such as diag/report.txt */
    }
    static func encodeStorageCleanRequest(_ what: StorageCleanWhat, seq: UInt16, tMs: UInt32) -> Data? {
        guard what.rawValue & ~0x07 == 0, what.rawValue != 0 else { return nil }      /* only the three defined bits, never "everything" */
        var w = Writer(type: .storageCleanReq, seq: seq, tMs: tMs); w.u8(0x01, what.rawValue); return w.result
    }
    struct StorageCleanResult: Equatable {
        enum Status: UInt8 { case done = 0, nothingToDo = 1, refusedStorageNotOK = 2, busyRecording = 3 }
        var statusRaw: UInt8 = 0; var bytesFreed: UInt32 = 0; var items = 0
        var status: Status? { Status(rawValue: statusRaw) }
        var words: String {
            switch status {
            case .done: return "Cleaned up \(items) item\(items == 1 ? "" : "s") on the BikeComputer."
            case .nothingToDo: return "Nothing to clean up on the BikeComputer."
            case .refusedStorageNotOK: return "The BikeComputer refused: its storage is not healthy. Cleanup never repairs storage over Bluetooth."
            case .busyRecording: return "The BikeComputer is recording a ride — try again after the ride."
            case nil: return "The BikeComputer answered with status \(statusRaw)."
            }
        }
    }
    static func decodeStorageCleanResult(_ d: Data) -> StorageCleanResult? {
        guard let (h, f) = parse(d), h.type == MsgType.storageCleanResult.rawValue else { return nil }
        var r = StorageCleanResult(); var got = false
        for x in f {
            switch (x.tag, x.value.count) {
            case (0x01, 1): r.statusRaw = x.value[x.value.startIndex]; got = true
            case (0x02, 4): r.bytesFreed = UInt32(uint(x.value))
            case (0x03, 2): r.items = Int(uint(x.value))
            default: break
            }
        }
        return got ? r : nil
    }
    static func encodeStorageCleanResult(_ r: StorageCleanResult, seq: UInt16, tMs: UInt32) -> Data {
        rawMessage(.storageCleanResult, seq: seq, tMs: tMs, [(0x01, Data([r.statusRaw])), (0x02, le(r.bytesFreed)), (0x03, le(UInt16(r.items)))])
    }

    // MARK: §8 DIAG_ACK with `03 u8 delete`
    /// The 1.2.3 ACK plus `03 delete = 1` (DIAG_AUTO only): the board may delete the verified report now. Old firmware
    /// skips the tag; without DIAG_AUTO enabled the app sends the 1.2.3 bytes exactly (`encodeDiagAck`).
    static func encodeDiagAck(reportId: UInt32, crc32: UInt32, delete: Bool, seq: UInt16, tMs: UInt32) -> Data? {
        var w = Writer(type: .diagAck, seq: seq, tMs: tMs)
        w.u32(0x01, reportId); w.u32(0x02, crc32); w.u8(0x03, delete ? 1 : 0)
        return w.result
    }
}
