import Foundation

/// BikeComputer Link protocol v1 — Swift twin of components/bc_core/bc_link.{h,c}.
/// Same rules: 8-byte header + tag/len/value fields, little-endian, unknown tags skipped, truncated messages rejected.
enum BCLink {
    static let verMajor: UInt8 = 1
    static let verMinor: UInt8 = 0
    static let maxMessage = 180

    static let serviceUUID = "B1CE0000-7E3A-4C55-9D2B-5A0E1C7C0000"
    static let infoUUID = "B1CE0002-7E3A-4C55-9D2B-5A0E1C7C0000"
    static let liveUUID = "B1CE0003-7E3A-4C55-9D2B-5A0E1C7C0000"
    static let inputUUID = "B1CE0004-7E3A-4C55-9D2B-5A0E1C7C0000"
    static let controlUUID = "B1CE0005-7E3A-4C55-9D2B-5A0E1C7C0000"
    static let syncUUID = "B1CE0006-7E3A-4C55-9D2B-5A0E1C7C0000"

    enum MsgType: UInt8 {
        case info = 0x01, live = 0x10
        case inTime = 0x20, inGPS = 0x21, inHR = 0x22, inWeather = 0x23, inBattery = 0x24
        case ctrlReq = 0x30, ctrlResp = 0x31, event = 0x40
        case syncReq = 0x50, syncRide = 0x51, syncEnd = 0x52      /* proposed in ios/SYNC_PROPOSAL.md; served by firmware only with caps & RIDE_SYNC */
    }

    enum Source: UInt8 {
        case unknown = 0, xds = 1, bleStrap = 2, phoneGPS = 3, appleWatch = 4, wearOS = 5, phoneStrap = 6, onboardGPS = 7
        case weatherKit = 8, openMeteo = 9, demo = 0x7F

        var label: String {
            switch self {
            case .xds: return "XDS"
            case .bleStrap: return "Strap"
            case .phoneGPS: return "Phone GPS"
            case .appleWatch: return "Apple Watch"
            case .wearOS: return "Wear OS"
            case .phoneStrap: return "Phone strap"
            case .onboardGPS: return "GPS"
            case .weatherKit: return "WeatherKit"
            case .openMeteo: return "Open-Meteo"
            case .demo: return "DEMO"
            case .unknown: return "?"
            }
        }
    }

    enum Command: UInt8 { case start = 1, pause = 2, resume = 3, stopRequest = 4, stopConfirm = 5 }
    enum Status: UInt8 { case ok = 0, badState = 1, needsConfirm = 2, unknown = 3, wrongRide = 4 }
    enum RideState: UInt8 { case idle = 0, running = 1, paused = 2, ended = 3 }

    struct Header { var type: UInt8; var flags: UInt8; var seq: UInt16; var tMs: UInt32 }

    // MARK: writer
    struct Writer {
        private(set) var data = Data()
        var ok = true
        init(type: MsgType, seq: UInt16, tMs: UInt32) {
            data.append(type.rawValue); data.append(0)
            data.append(le(seq)); data.append(le(tMs))
        }
        mutating func field(_ tag: UInt8, _ value: Data) {
            guard ok, data.count + 2 + value.count <= BCLink.maxMessage, value.count < 256 else { ok = false; return }
            data.append(tag); data.append(UInt8(value.count)); data.append(value)
        }
        mutating func u8(_ tag: UInt8, _ v: UInt8) { field(tag, Data([v])) }
        mutating func u16(_ tag: UInt8, _ v: UInt16) { field(tag, le(v)) }
        mutating func u32(_ tag: UInt8, _ v: UInt32) { field(tag, le(v)) }
        mutating func u64(_ tag: UInt8, _ v: UInt64) { field(tag, le(v)) }
        mutating func s16(_ tag: UInt8, _ v: Int16) { field(tag, le(UInt16(bitPattern: v))) }
        mutating func s32(_ tag: UInt8, _ v: Int32) { field(tag, le(UInt32(bitPattern: v))) }
        mutating func str(_ tag: UInt8, _ s: String) { field(tag, Data(s.utf8.prefix(31))) }
        var result: Data? { ok ? data : nil }
    }

    // MARK: reader
    struct Field { let tag: UInt8; let value: Data }

    /// Header + fields, or nil for a short message or a field list that runs past the end (rejected whole).
    static func parse(_ d: Data) -> (Header, [Field])? {
        guard d.count >= 8, d.count <= 512 else { return nil }
        let b = [UInt8](d)
        let h = Header(type: b[0], flags: b[1], seq: UInt16(b[2]) | UInt16(b[3]) << 8,
                       tMs: UInt32(b[4]) | UInt32(b[5]) << 8 | UInt32(b[6]) << 16 | UInt32(b[7]) << 24)
        var fields: [Field] = []
        var p = 8
        while p < b.count {
            guard p + 2 <= b.count else { return nil }
            let n = Int(b[p + 1])
            guard p + 2 + n <= b.count else { return nil }
            fields.append(Field(tag: b[p], value: Data(b[(p + 2)..<(p + 2 + n)])))
            p += 2 + n
        }
        return (h, fields)
    }

    static func uint(_ v: Data) -> UInt64 { var x: UInt64 = 0; for (i, byte) in v.enumerated() where i < 8 { x |= UInt64(byte) << (8 * UInt64(i)) }; return x }
    static func sint(_ v: Data) -> Int64 {
        var x = uint(v)
        if v.count < 8, (x >> (8 * UInt64(v.count) - 1)) & 1 == 1 { x |= ~0 << (8 * UInt64(v.count)) }
        return Int64(bitPattern: x)
    }

    // MARK: messages
    struct Info: Equatable {
        var verMajor: UInt8 = 0, verMinor: UInt8 = 0, fw = "", name = "", caps: UInt32 = 0, maxMsg: UInt16 = 0
        /// Proposed INFO tag 0x07: the board's 6-byte BLE address, so rides can be keyed per board on every phone. nil until the firmware sends it.
        var deviceId: String? = nil
        static let capLive: UInt32 = 0x01, capGPS: UInt32 = 0x02, capHR: UInt32 = 0x04, capWeather: UInt32 = 0x08, capCtrl: UInt32 = 0x10, capTime: UInt32 = 0x20, capRideSync: UInt32 = 0x40
        var hasRideSync: Bool { caps & Info.capRideSync != 0 }
    }

    static func decodeInfo(_ d: Data) -> Info? {
        guard let (h, f) = parse(d), h.type == MsgType.info.rawValue else { return nil }
        var i = Info()
        for x in f {
            switch (x.tag, x.value.count) {
            case (0x01, 1): i.verMajor = x.value[x.value.startIndex]
            case (0x02, 1): i.verMinor = x.value[x.value.startIndex]
            case (0x03, _): i.fw = String(decoding: x.value, as: UTF8.self)
            case (0x04, _): i.name = String(decoding: x.value, as: UTF8.self)
            case (0x05, 4): i.caps = UInt32(uint(x.value))
            case (0x06, 2): i.maxMsg = UInt16(uint(x.value))
            case (0x07, 6): i.deviceId = x.value.map { String(format: "%02x", $0) }.joined(separator: ":")
            default: break
            }
        }
        return i.verMajor != 0 ? i : nil
    }

    // MARK: ride history sync (proposal — see ios/SYNC_PROPOSAL.md; the app only uses it when INFO caps has RIDE_SYNC)
    /// One finished ride as the board stores it (bc_ride_summary_t / history line R2). -1 fields become nil.
    struct RideSummary: Equatable {
        var id: Int = 0
        var demo = false, recovered = false
        var durationS: Int = 0, pausedS: Int = 0
        var avgPower: Int?, maxPower: Int?, avgCadence: Int?, avgHR: Int?, maxHR: Int?
        var powerS: Int = 0, cadS: Int = 0, hrS: Int = 0
        var zoneS: [Int] = Array(repeating: 0, count: 7); var zonesValid = false
        var ftpW: Int = 0, ftpHow: Int = 0
        var kj: Int?
        var best20: Int?
        var inbandPct: Int?
        var ftpNew: Int = 0, ftpSuggestedOnly = false
        var distanceM: Int = 0, distSrc: Int = 0
        var startEpochS: Int = 0          /* 0 = the board never had the wall clock during that ride */
        var coach = ""
    }

    static func encodeSyncRequest(afterRideId: UInt16, maxCount: UInt8, seq: UInt16, tMs: UInt32) -> Data? {
        var w = Writer(type: .syncReq, seq: seq, tMs: tMs)
        w.u16(0x01, afterRideId); w.u8(0x02, maxCount)
        return w.result
    }

    static func encodeSyncRide(_ r: RideSummary, seq: UInt16, tMs: UInt32) -> Data? {
        var w = Writer(type: .syncRide, seq: seq, tMs: tMs)
        w.u16(0x01, UInt16(r.id)); w.u8(0x02, (r.demo ? 1 : 0) | (r.recovered ? 2 : 0))
        w.u32(0x03, UInt32(r.durationS)); w.u32(0x04, UInt32(r.pausedS))
        w.s16(0x05, Int16(r.avgPower ?? -1)); w.s16(0x06, Int16(r.maxPower ?? -1)); w.s16(0x07, Int16(r.avgCadence ?? -1))
        w.s16(0x08, Int16(r.avgHR ?? -1)); w.s16(0x09, Int16(r.maxHR ?? -1))
        w.u32(0x0A, UInt32(r.powerS)); w.u32(0x0B, UInt32(r.cadS)); w.u32(0x0C, UInt32(r.hrS))
        if r.zonesValid { var z = Data(); for v in r.zoneS.prefix(7) { z.append(le(UInt32(v))) }; w.field(0x0D, z) }
        w.s16(0x0E, Int16(r.ftpW)); w.u8(0x0F, UInt8(r.ftpHow))
        w.s16(0x10, Int16(r.kj ?? -1)); w.s16(0x11, Int16(r.best20 ?? -1)); w.field(0x12, Data([UInt8(bitPattern: Int8(r.inbandPct ?? -1))]))
        w.u16(0x13, UInt16(r.ftpNew)); w.u8(0x14, r.ftpSuggestedOnly ? 1 : 0)
        w.u32(0x15, UInt32(r.distanceM)); w.u8(0x16, UInt8(r.distSrc)); w.u32(0x17, UInt32(r.startEpochS))
        if !r.coach.isEmpty { w.field(0x18, Data(r.coach.utf8.prefix(60))) }
        return w.result
    }

    static func decodeSyncRide(_ d: Data) -> RideSummary? {
        guard let (h, f) = parse(d), h.type == MsgType.syncRide.rawValue else { return nil }
        var r = RideSummary(); var gotId = false
        func opt(_ v: Data) -> Int? { let x = Int(sint(v)); return x < 0 ? nil : x }
        for x in f {
            let v = x.value
            switch (x.tag, v.count) {
            case (0x01, 2): r.id = Int(uint(v)); gotId = true
            case (0x02, 1): r.demo = v[v.startIndex] & 1 != 0; r.recovered = v[v.startIndex] & 2 != 0
            case (0x03, 4): r.durationS = Int(uint(v))
            case (0x04, 4): r.pausedS = Int(uint(v))
            case (0x05, 2): r.avgPower = opt(v)
            case (0x06, 2): r.maxPower = opt(v)
            case (0x07, 2): r.avgCadence = opt(v)
            case (0x08, 2): r.avgHR = opt(v)
            case (0x09, 2): r.maxHR = opt(v)
            case (0x0A, 4): r.powerS = Int(uint(v))
            case (0x0B, 4): r.cadS = Int(uint(v))
            case (0x0C, 4): r.hrS = Int(uint(v))
            case (0x0D, 28): r.zonesValid = true; r.zoneS = (0..<7).map { Int(uint(v.subdata(in: (v.startIndex + 4 * $0)..<(v.startIndex + 4 * $0 + 4)))) }
            case (0x0E, 2): r.ftpW = Int(sint(v))
            case (0x0F, 1): r.ftpHow = Int(v[v.startIndex])
            case (0x10, 2): r.kj = opt(v)
            case (0x11, 2): r.best20 = opt(v)
            case (0x12, 1): r.inbandPct = opt(v)
            case (0x13, 2): r.ftpNew = Int(uint(v))
            case (0x14, 1): r.ftpSuggestedOnly = v[v.startIndex] != 0
            case (0x15, 4): r.distanceM = Int(uint(v))
            case (0x16, 1): r.distSrc = Int(v[v.startIndex])
            case (0x17, 4): r.startEpochS = Int(uint(v))
            case (0x18, _): r.coach = String(decoding: v, as: UTF8.self)
            default: break
            }
        }
        return gotId ? r : nil
    }

    struct SyncEnd: Equatable { var count: Int = 0; var total: Int = 0; var more = false }
    static func decodeSyncEnd(_ d: Data) -> SyncEnd? {
        guard let (h, f) = parse(d), h.type == MsgType.syncEnd.rawValue else { return nil }
        var e = SyncEnd()
        for x in f {
            switch (x.tag, x.value.count) {
            case (0x01, 2): e.count = Int(uint(x.value))
            case (0x02, 2): e.total = Int(uint(x.value))
            case (0x03, 1): e.more = x.value[x.value.startIndex] != 0
            default: break
            }
        }
        return e
    }

    /// Live values from the board. A nil value means "no data right now" — never a held value.
    struct Live: Equatable {
        var powerW: Int?; var powerAgeMs: Int?
        var cadenceRpm: Int?; var cadAgeMs: Int?
        var hrBpm: Int?; var hrSource: Source = .unknown; var hrAgeMs: Int?
        var rideState: RideState = .idle; var rideId: Int = 0; var elapsedS: Int = 0; var distanceM: Int = 0
        var cueId: Int = 0; var batteryPct: Int?; var meterLink: Int = 0; var meterGaps: Int = 0
        var demo = false
        var seq: UInt16 = 0; var boardTimeMs: UInt32 = 0
    }

    static func decodeLive(_ d: Data) -> Live? {
        guard let (h, f) = parse(d), h.type == MsgType.live.rawValue else { return nil }
        var l = Live(); l.seq = h.seq; l.boardTimeMs = h.tMs
        for x in f {
            let v = x.value
            switch (x.tag, v.count) {
            case (0x01, 2): l.powerW = Int(uint(v))
            case (0x02, 2): l.powerAgeMs = Int(uint(v))
            case (0x03, 1): l.cadenceRpm = Int(v[v.startIndex])
            case (0x04, 2): l.cadAgeMs = Int(uint(v))
            case (0x05, 1): l.hrBpm = Int(v[v.startIndex])
            case (0x06, 1): l.hrSource = Source(rawValue: v[v.startIndex]) ?? .unknown
            case (0x07, 2): l.hrAgeMs = Int(uint(v))
            case (0x08, 1): l.rideState = RideState(rawValue: v[v.startIndex]) ?? .idle
            case (0x09, 2): l.rideId = Int(uint(v))
            case (0x0A, 4): l.elapsedS = Int(uint(v))
            case (0x0B, 4): l.distanceM = Int(uint(v))
            case (0x0C, 1): l.cueId = Int(v[v.startIndex])
            case (0x0D, 1): l.batteryPct = v[v.startIndex] == 0xFF ? nil : Int(v[v.startIndex])
            case (0x0E, 1): l.meterLink = Int(v[v.startIndex])
            case (0x0F, 2): l.meterGaps = Int(uint(v))
            case (0x10, 1): l.demo = v[v.startIndex] != 0
            default: break
            }
        }
        return l
    }

    static func encodeTime(epochMs: UInt64, uncertaintyMs: UInt16, tzMinutes: Int16, seq: UInt16, tMs: UInt32) -> Data? {
        var w = Writer(type: .inTime, seq: seq, tMs: tMs)
        w.u64(0x01, epochMs); w.u16(0x02, uncertaintyMs); w.s16(0x03, tzMinutes)
        return w.result
    }

    struct GPSFix {
        var latE7: Int32; var lonE7: Int32; var altDm: Int32?; var haccDm: UInt16; var vaccDm: UInt16
        var speedCms: UInt16?; var courseCdeg: UInt16?; var fixEpochMs: UInt64; var source: Source = .phoneGPS
    }

    static func encodeGPS(_ g: GPSFix, seq: UInt16, tMs: UInt32) -> Data? {
        var w = Writer(type: .inGPS, seq: seq, tMs: tMs)
        w.s32(0x01, g.latE7); w.s32(0x02, g.lonE7)
        if let a = g.altDm { w.s32(0x03, a) }
        w.u16(0x04, g.haccDm); w.u16(0x05, g.vaccDm)
        if let s = g.speedCms { w.u16(0x06, s) }
        if let c = g.courseCdeg { w.u16(0x07, c) }
        w.u64(0x08, g.fixEpochMs); w.u8(0x09, g.source.rawValue)
        return w.result
    }

    static func encodeHR(bpm: UInt8, source: Source, sampleEpochMs: UInt64, quality: UInt8, seq: UInt16, tMs: UInt32) -> Data? {
        var w = Writer(type: .inHR, seq: seq, tMs: tMs)
        w.u8(0x01, bpm); w.u8(0x02, source.rawValue); w.u64(0x03, sampleEpochMs); w.u8(0x04, quality)
        return w.result
    }

    static func encodeBattery(phonePct: UInt8?, watchPct: UInt8?, seq: UInt16, tMs: UInt32) -> Data? {
        var w = Writer(type: .inBattery, seq: seq, tMs: tMs)
        w.u8(0x01, phonePct ?? 0xFF); w.u8(0x02, watchPct ?? 0xFF)
        return w.result
    }

    static func encodeControl(reqId: UInt16, cmd: Command, rideId: UInt16, seq: UInt16, tMs: UInt32) -> Data? {
        var w = Writer(type: .ctrlReq, seq: seq, tMs: tMs)
        w.u16(0x01, reqId); w.u8(0x02, cmd.rawValue); w.u16(0x03, rideId)
        return w.result
    }

    struct ControlResponse: Equatable { var reqId: UInt16 = 0; var status: Status = .unknown; var rideState: RideState = .idle; var rideId: UInt16 = 0 }

    static func decodeControlResponse(_ d: Data) -> ControlResponse? {
        guard let (h, f) = parse(d), h.type == MsgType.ctrlResp.rawValue else { return nil }
        var r = ControlResponse()
        for x in f {
            let v = x.value
            switch (x.tag, v.count) {
            case (0x01, 2): r.reqId = UInt16(uint(v))
            case (0x02, 1): r.status = Status(rawValue: v[v.startIndex]) ?? .unknown
            case (0x03, 1): r.rideState = RideState(rawValue: v[v.startIndex]) ?? .idle
            case (0x04, 2): r.rideId = UInt16(uint(v))
            default: break
            }
        }
        return r
    }

    // MARK: helpers
    static func le<T: FixedWidthInteger>(_ v: T) -> Data { withUnsafeBytes(of: v.littleEndian) { Data($0) } }
}
