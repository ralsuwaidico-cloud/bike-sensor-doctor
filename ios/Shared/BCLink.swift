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
    static let eventsUUID = "B1CE0007-7E3A-4C55-9D2B-5A0E1C7C0000"

    /// Readable name of a Link characteristic for diagnostics ("Live", "Events", …); other UUIDs as given.
    static func shortName(_ uuid: String) -> String {
        switch uuid.uppercased() {
        case infoUUID: return "Info"; case liveUUID: return "Live"; case inputUUID: return "Input"; case controlUUID: return "Control"
        case syncUUID: return "Sync"; case eventsUUID: return "Events"; default: return uuid.uppercased()
        }
    }

    enum MsgType: UInt8 {
        case info = 0x01, live = 0x10
        case inTime = 0x20, inGPS = 0x21, inHR = 0x22, inWeather = 0x23, inBattery = 0x24
        case ctrlReq = 0x30, ctrlResp = 0x31, event = 0x40
        case syncReq = 0x50, syncRide = 0x51, syncEnd = 0x52      /* 1.1 ride-history sync; served by firmware only with caps & RIDE_SYNC */
        /* 1.2 (firmware 0.6.0, docs/LINK_V1_2_SPEC.md) — all on the Control characteristic, gated on caps */
        case wifiScanReq = 0x60, wifiScanResult = 0x61, wifiScanEnd = 0x62, wifiSet = 0x63, wifiForget = 0x64, wifiStatus = 0x65, wifiStatusReq = 0x66
        case profileGet = 0x70, profileSet = 0x71, profile = 0x72, profileAck = 0x73
        case settingsSet = 0x74, settings = 0x75, settingsGet = 0x76
    }

    enum Source: UInt8 {
        case unknown = 0, xds = 1, bleStrap = 2, phoneGPS = 3, appleWatch = 4, wearOS = 5, phoneStrap = 6, onboardGPS = 7
        case weatherKit = 8, openMeteo = 9, bleCSC = 10, demo = 0x7F

        var label: String {
            switch self {
            case .xds: return "Power meter"   // protocol id stays BC_SRC_XDS = 1; label is brand-neutral
            case .bleStrap: return "Strap"
            case .phoneGPS: return "Phone GPS"
            case .appleWatch: return "Apple Watch"
            case .wearOS: return "Wear OS"
            case .phoneStrap: return "Phone strap"
            case .onboardGPS: return "GPS"
            case .weatherKit: return "WeatherKit"
            case .openMeteo: return "Open-Meteo"
            case .bleCSC: return "Cadence/speed sensor"
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
        static let capWiFi: UInt32 = 0x80, capProfileSync: UInt32 = 0x100, capSettings: UInt32 = 0x200
        var hasRideSync: Bool { caps & Info.capRideSync != 0 }
        var hasWiFi: Bool { caps & Info.capWiFi != 0 }
        var hasProfileSync: Bool { caps & Info.capProfileSync != 0 }
        var hasSettings: Bool { caps & Info.capSettings != 0 }
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

    // MARK: 1.2 Wi-Fi provisioning (cap 0x80) — docs/LINK_V1_2_SPEC.md
    struct WiFiNetwork: Equatable, Identifiable {
        var id: String { ssid }
        var ssid = ""; var rssi: Int = -100; var secured = true; var channel = 0; var saved = false
    }
    struct WiFiScanEnd: Equatable { var count = 0; var err = 0
        var errorText: String? { switch err { case 0: return nil; case 1: return "Wi-Fi radio is off on the board"; case 2: return "board busy (ride running)"; default: return "scan failed" } } }
    enum WiFiState: UInt8 { case off = 0, disconnected = 1, scanning = 2, connecting = 3, connected = 4, connectedNoInternet = 5
        var label: String { switch self { case .off: return "Wi-Fi off"; case .disconnected: return "Disconnected"; case .scanning: return "Scanning…"; case .connecting: return "Connecting…"; case .connected: return "Connected"; case .connectedNoInternet: return "Connected, no internet" } } }
    enum WiFiError: UInt8 { case none = 0, wrongPassword = 1, notFound = 2, timeout = 3, other = 4
        var label: String? { switch self { case .none: return nil; case .wrongPassword: return "Wrong password"; case .notFound: return "Network not found (2.4 GHz only)"; case .timeout: return "Timed out"; case .other: return "Could not connect" } } }
    struct WiFiStatus: Equatable { var state: WiFiState = .off; var error: WiFiError = .none; var ssid = ""; var rssi: Int? = nil; var savedCount = 0; var radioOn = false }

    static func encodeWiFiScanRequest(max: UInt8? = nil, seq: UInt16, tMs: UInt32) -> Data? {
        var w = Writer(type: .wifiScanReq, seq: seq, tMs: tMs)
        if let m = max { w.u8(0x01, m) }
        return w.result
    }
    static func encodeWiFiStatusRequest(seq: UInt16, tMs: UInt32) -> Data? { Writer(type: .wifiStatusReq, seq: seq, tMs: tMs).result }
    /// ssid 1–32 bytes, password 0–63 bytes (empty = open network). nil when the lengths are out of range.
    static func encodeWiFiSet(ssid: String, password: String, connectNow: Bool = true, save: Bool = true, seq: UInt16, tMs: UInt32) -> Data? {
        let s = Data(ssid.utf8), p = Data(password.utf8)
        guard (1...32).contains(s.count), p.count <= 63 else { return nil }
        var w = Writer(type: .wifiSet, seq: seq, tMs: tMs)
        w.field(0x01, s); w.field(0x02, p); w.u8(0x03, (connectNow ? 1 : 0) | (save ? 2 : 0))
        return w.result
    }
    static func encodeWiFiForget(ssid: String, seq: UInt16, tMs: UInt32) -> Data? {
        let s = Data(ssid.utf8); guard (1...32).contains(s.count) else { return nil }
        var w = Writer(type: .wifiForget, seq: seq, tMs: tMs); w.field(0x01, s); return w.result
    }
    static func decodeWiFiScanResult(_ d: Data) -> WiFiNetwork? {
        guard let (h, f) = parse(d), h.type == MsgType.wifiScanResult.rawValue else { return nil }
        var n = WiFiNetwork(); var got = false
        for x in f {
            let v = x.value
            switch (x.tag, v.count) {
            case (0x01, 1...32): n.ssid = String(decoding: v, as: UTF8.self); got = true
            case (0x02, 1): n.rssi = Int(Int8(bitPattern: v[v.startIndex]))
            case (0x03, 1): n.secured = v[v.startIndex] != 0
            case (0x04, 1): n.channel = Int(v[v.startIndex])
            case (0x05, 1): n.saved = v[v.startIndex] != 0
            default: break
            }
        }
        return got ? n : nil
    }
    static func decodeWiFiScanEnd(_ d: Data) -> WiFiScanEnd? {
        guard let (h, f) = parse(d), h.type == MsgType.wifiScanEnd.rawValue else { return nil }
        var e = WiFiScanEnd()
        for x in f { switch (x.tag, x.value.count) { case (0x01, 1): e.count = Int(x.value[x.value.startIndex]); case (0x02, 1): e.err = Int(x.value[x.value.startIndex]); default: break } }
        return e
    }
    static func decodeWiFiStatus(_ d: Data) -> WiFiStatus? {
        guard let (h, f) = parse(d), h.type == MsgType.wifiStatus.rawValue else { return nil }
        var s = WiFiStatus()
        for x in f {
            let v = x.value
            switch (x.tag, v.count) {
            case (0x01, 1): s.state = WiFiState(rawValue: v[v.startIndex]) ?? .off
            case (0x02, 1): s.error = WiFiError(rawValue: v[v.startIndex]) ?? .other
            case (0x03, _): s.ssid = String(decoding: v, as: UTF8.self)
            case (0x04, 1): s.rssi = Int(Int8(bitPattern: v[v.startIndex]))
            case (0x05, 1): s.savedCount = Int(v[v.startIndex])
            case (0x06, 1): s.radioOn = v[v.startIndex] != 0
            default: break
            }
        }
        return s
    }

    // MARK: 1.2 athlete profile sync (cap 0x100)
    /// The shared athlete settings as they travel over the link. Optional = "not carried / unknown" (0 on the wire for numbers).
    struct ProfileMessage: Equatable {
        var version: UInt32 = 0
        var updatedEpochS: UInt32? = nil
        var name: String? = nil
        var ftpW: Int? = nil
        var ftpHow: Int? = nil          /* 0 assumed, 1 entered, 2 estimated from rides, 3 tested */
        var weightKgX10: Int? = nil
        var birthYear: Int? = nil       /* 0 → nil */
        var maxHR: Int? = nil           /* 0 → nil */
        var restHR: Int? = nil
        var units: Int? = nil           /* 0 metric, 1 imperial */
        var hoursPerWeek: Int? = nil
        var level: Int? = nil           /* 0 new, 1 regular, 2 experienced */
        var goal: Int? = nil            /* 0 fitness, 1 endurance, 2 climbing, 3 event, 4 weight */
        var lthr: Int? = nil
        /* PROFILE (board → phone) only */
        var source: Int? = nil          /* 0 device-only, 1 phone-synced */
        var boardSavedEpochS: UInt32? = nil
    }
    struct ProfileAck: Equatable { var version: UInt32 = 0; var status = 0; var boardVersion: UInt32 = 0
        var applied: Bool { status == 0 }
        var statusText: String { switch status { case 0: return "applied"; case 1: return "board has a newer version"; case 2: return "a value was rejected"; default: return "unknown status \(status)" } } }

    static func encodeProfileGet(seq: UInt16, tMs: UInt32) -> Data? { Writer(type: .profileGet, seq: seq, tMs: tMs).result }
    private static func writeProfileFields(_ w: inout Writer, _ p: ProfileMessage) {
        if let v = p.updatedEpochS { w.u32(0x02, v) }
        if let n = p.name { w.field(0x03, Data(n.utf8.prefix(24))) }
        if let v = p.ftpW { w.u16(0x04, UInt16(clamping: v)) }
        if let v = p.ftpHow { w.u8(0x05, UInt8(clamping: v)) }
        if let v = p.weightKgX10 { w.u16(0x06, UInt16(clamping: v)) }
        if let v = p.birthYear { w.u16(0x07, UInt16(clamping: v)) }
        if let v = p.maxHR { w.u8(0x08, UInt8(clamping: v)) }
        if let v = p.restHR { w.u8(0x09, UInt8(clamping: v)) }
        if let v = p.units { w.u8(0x0A, UInt8(clamping: v)) }
        if let v = p.hoursPerWeek { w.u8(0x0B, UInt8(clamping: v)) }
        if let v = p.level { w.u8(0x0C, UInt8(clamping: v)) }
        if let v = p.goal { w.u8(0x0D, UInt8(clamping: v)) }
        if let v = p.lthr { w.u8(0x0E, UInt8(clamping: v)) }
    }
    static func encodeProfileSet(_ p: ProfileMessage, seq: UInt16, tMs: UInt32) -> Data? {
        guard p.version > 0 else { return nil }
        var w = Writer(type: .profileSet, seq: seq, tMs: tMs)
        w.u32(0x01, p.version); writeProfileFields(&w, p)
        return w.result
    }
    /// Test helper mirroring the board's PROFILE reply.
    static func encodeProfile(_ p: ProfileMessage, seq: UInt16, tMs: UInt32) -> Data? {
        var w = Writer(type: .profile, seq: seq, tMs: tMs)
        w.u32(0x01, p.version); writeProfileFields(&w, p)
        if let s = p.source { w.u8(0x0F, UInt8(clamping: s)) }
        if let t = p.boardSavedEpochS { w.u32(0x10, t) }
        return w.result
    }
    static func decodeProfile(_ d: Data) -> ProfileMessage? {
        guard let (h, f) = parse(d), h.type == MsgType.profile.rawValue || h.type == MsgType.profileSet.rawValue else { return nil }
        var p = ProfileMessage()
        func z(_ v: Data) -> Int? { let x = Int(uint(v)); return x == 0 ? nil : x }
        for x in f {
            let v = x.value
            switch (x.tag, v.count) {
            case (0x01, 4): p.version = UInt32(uint(v))
            case (0x02, 4): p.updatedEpochS = UInt32(uint(v))
            case (0x03, _): p.name = String(decoding: v, as: UTF8.self)
            case (0x04, 2): p.ftpW = Int(uint(v))
            case (0x05, 1): p.ftpHow = Int(v[v.startIndex])
            case (0x06, 2): p.weightKgX10 = z(v)
            case (0x07, 2): p.birthYear = z(v)
            case (0x08, 1): p.maxHR = z(v)
            case (0x09, 1): p.restHR = z(v)
            case (0x0A, 1): p.units = Int(v[v.startIndex])
            case (0x0B, 1): p.hoursPerWeek = Int(v[v.startIndex])
            case (0x0C, 1): p.level = Int(v[v.startIndex])
            case (0x0D, 1): p.goal = Int(v[v.startIndex])
            case (0x0E, 1): p.lthr = z(v)
            case (0x0F, 1): p.source = Int(v[v.startIndex])
            case (0x10, 4): p.boardSavedEpochS = UInt32(uint(v))
            default: break
            }
        }
        return p
    }
    static func decodeProfileAck(_ d: Data) -> ProfileAck? {
        guard let (h, f) = parse(d), h.type == MsgType.profileAck.rawValue else { return nil }
        var a = ProfileAck()
        for x in f { switch (x.tag, x.value.count) { case (0x01, 4): a.version = UInt32(uint(x.value)); case (0x02, 1): a.status = Int(x.value[x.value.startIndex]); case (0x03, 4): a.boardVersion = UInt32(uint(x.value)); default: break } }
        return a
    }
    /// Test helper mirroring the board's PROFILE_ACK.
    static func encodeProfileAck(_ a: ProfileAck, seq: UInt16, tMs: UInt32) -> Data? {
        var w = Writer(type: .profileAck, seq: seq, tMs: tMs); w.u32(0x01, a.version); w.u8(0x02, UInt8(clamping: a.status)); w.u32(0x03, a.boardVersion); return w.result
    }

    // MARK: 1.2 device settings (cap 0x200)
    /// Board settings on the wire. Optional = not carried. `supportedMask` bit n = tag n+1 supported (reply only).
    struct SettingsMessage: Equatable {
        var version: UInt32 = 0
        var brightnessPct: Int? = nil          /* tag 02, 10–100 */
        var screenTimeoutS: Int? = nil         /* tag 03, 0 never */
        var wakeGesture: Int? = nil            /* tag 04, 0 triple, 1 double, 2 any touch */
        var phoneLinkEnabled: Bool? = nil      /* tag 05 */
        var hrPref: Int? = nil                 /* tag 06, 0 strap first, 1 watch first */
        var autoSleepMin: Int? = nil           /* tag 07, 0 off */
        var rideLayout: Int? = nil             /* tag 08, 0 A, 1 B, 2 C */
        var wakeOnCue: Bool? = nil             /* tag 09 */
        var units: Int? = nil                  /* tag 0A */
        var status: Int? = nil                 /* tag 0F reply: 0 applied, 1 rejected older, 2 bad value, 3 unsupported tag */
        var supportedMask: UInt32? = nil       /* tag 10 */
        func supports(tag: Int) -> Bool { guard let m = supportedMask, tag >= 1 else { return false }; return m & (1 << UInt32(tag - 1)) != 0 }
        var statusText: String { switch status { case 0: return "applied"; case 1: return "board has a newer version"; case 2: return "a value was rejected"; case 3: return "a setting is not supported by this firmware"; case nil: return "no reply"; default: return "unknown status" } }
    }
    static func encodeSettingsGet(seq: UInt16, tMs: UInt32) -> Data? { Writer(type: .settingsGet, seq: seq, tMs: tMs).result }
    private static func writeSettingsFields(_ w: inout Writer, _ s: SettingsMessage) {
        if let v = s.brightnessPct { w.u8(0x02, UInt8(clamping: v)) }
        if let v = s.screenTimeoutS { w.u16(0x03, UInt16(clamping: v)) }
        if let v = s.wakeGesture { w.u8(0x04, UInt8(clamping: v)) }
        if let v = s.phoneLinkEnabled { w.u8(0x05, v ? 1 : 0) }
        if let v = s.hrPref { w.u8(0x06, UInt8(clamping: v)) }
        if let v = s.autoSleepMin { w.u16(0x07, UInt16(clamping: v)) }
        if let v = s.rideLayout { w.u8(0x08, UInt8(clamping: v)) }
        if let v = s.wakeOnCue { w.u8(0x09, v ? 1 : 0) }
        if let v = s.units { w.u8(0x0A, UInt8(clamping: v)) }
    }
    static func encodeSettingsSet(_ s: SettingsMessage, seq: UInt16, tMs: UInt32) -> Data? {
        guard s.version > 0 else { return nil }
        var w = Writer(type: .settingsSet, seq: seq, tMs: tMs); w.u32(0x01, s.version); writeSettingsFields(&w, s); return w.result
    }
    /// Test helper mirroring the board's SETTINGS reply.
    static func encodeSettings(_ s: SettingsMessage, seq: UInt16, tMs: UInt32) -> Data? {
        var w = Writer(type: .settings, seq: seq, tMs: tMs); w.u32(0x01, s.version); writeSettingsFields(&w, s)
        if let st = s.status { w.u8(0x0F, UInt8(clamping: st)) }
        if let m = s.supportedMask { w.u32(0x10, m) }
        return w.result
    }
    static func decodeSettings(_ d: Data) -> SettingsMessage? {
        guard let (h, f) = parse(d), h.type == MsgType.settings.rawValue || h.type == MsgType.settingsSet.rawValue else { return nil }
        var s = SettingsMessage()
        for x in f {
            let v = x.value
            switch (x.tag, v.count) {
            case (0x01, 4): s.version = UInt32(uint(v))
            case (0x02, 1): s.brightnessPct = Int(v[v.startIndex])
            case (0x03, 2): s.screenTimeoutS = Int(uint(v))
            case (0x04, 1): s.wakeGesture = Int(v[v.startIndex])
            case (0x05, 1): s.phoneLinkEnabled = v[v.startIndex] != 0
            case (0x06, 1): s.hrPref = Int(v[v.startIndex])
            case (0x07, 2): s.autoSleepMin = Int(uint(v))
            case (0x08, 1): s.rideLayout = Int(v[v.startIndex])
            case (0x09, 1): s.wakeOnCue = v[v.startIndex] != 0
            case (0x0A, 1): s.units = Int(v[v.startIndex])
            case (0x0F, 1): s.status = Int(v[v.startIndex])
            case (0x10, 4): s.supportedMask = UInt32(uint(v))
            default: break
            }
        }
        return s
    }

    // MARK: helpers
    static func le<T: FixedWidthInteger>(_ v: T) -> Data { withUnsafeBytes(of: v.littleEndian) { Data($0) } }

    // MARK: EVENT 0x40 (Events characteristic 0007) — 1.2.1 link_diag (firmware 0.7.0), battery notice (flag-gated)
    /// `01 u8 event_id` · `02 u8` · `03 u16` · `04 u8`; the meaning of tags 2–4 depends on the event id.
    struct Event: Equatable {
        var eventId: Int = 0
        var b2: Int? = nil, w3: Int? = nil, b4: Int? = nil
        var isLinkDiag: Bool { eventId == 0x20 }
        var isBatteryNotice: Bool { eventId == 0x10 }
    }
    /// What the board reports once per connection (event_id 0x20): why the previous link ended, how many phones it
    /// remembers and the state of profile sync on its side. Informational — shown on the Connection diagnostics page.
    struct LinkDiag: Equatable {
        var reason = 0, bonds = 0, syncState = 0
        var reasonText: String {
            switch reason {
            case 0: return "none"; case 1: return "the phone ended it"; case 2: return "the board ended it"; case 3: return "timeout / out of range"
            case 4: return "keys missing (stale pairing)"; case 5: return "authentication failed"; case 6: return "failed to establish"; default: return "other (\(reason))"
            }
        }
        var syncText: String { switch syncState { case 0: return "device-only"; case 1: return "synced"; case 2: return "pending"; case 3: return "failed"; default: return "unknown (\(syncState))" } }
    }
    static func decodeEvent(_ d: Data) -> Event? {
        guard let (h, f) = parse(d), h.type == MsgType.event.rawValue else { return nil }
        var e = Event()
        var seen = false
        for x in f {
            switch (x.tag, x.value.count) {
            case (0x01, 1): e.eventId = Int(x.value[x.value.startIndex]); seen = true
            case (0x02, 1): e.b2 = Int(x.value[x.value.startIndex])
            case (0x03, 2): e.w3 = Int(uint(x.value))
            case (0x04, 1): e.b4 = Int(x.value[x.value.startIndex])
            default: break
            }
        }
        return seen ? e : nil
    }
    static func linkDiag(from e: Event) -> LinkDiag? {
        guard e.isLinkDiag else { return nil }
        return LinkDiag(reason: e.b2 ?? 0, bonds: e.w3 ?? 0, syncState: e.b4 ?? 0)
    }

    // MARK: 1.2.2 SENSOR_DIAG (firmware 0.7.2) — docs/LINK_V1_2_SPEC.md section "1.2.2"
    /// EVENT 0x40, `01 u8 event_id = 0x21`. One message per board sensor link, sent on every stage change, every 5 s
    /// while a paired link is below VALID, and right after the phone connects. Tags (little-endian):
    /// `02 u8 sensor` · `03 u8 stage` · `04 u32 packets` · `05 u16 rejected` · `06 u16 packet age (ds, 0xFFFF none)` ·
    /// `07 u16 valid age (ds, 0xFFFF none)` · `08 utf8 ≤ 20 last error`. Unknown tags and wrong-length fields are skipped.
    static let sensorDiagEventId = 0x21
    struct SensorDiag: Equatable, Codable {
        enum Sensor: UInt8, Codable, CaseIterable { case power = 1, hrStrap = 2, csc = 3
            var title: String { switch self { case .power: return "Power meter"; case .hrStrap: return "Heart-rate strap"; case .csc: return "Speed / cadence sensor" } } }
        enum Stage: UInt8, Codable { case notPaired = 0, searching = 1, connecting = 2, connected = 3, subscribed = 4, receiving = 5, valid = 6, stale = 7, error = 8
            /// The words the board shows (spec 1.2.2) — the phone uses the same ones.
            var words: String {
                switch self {
                case .notPaired: return "Not paired"; case .searching: return "Searching"; case .connecting: return "Connecting"
                case .connected, .subscribed: return "Connected — waiting for data"; case .receiving: return "Receiving — no valid readings"
                case .valid: return "Live"; case .stale: return "Data stale"; case .error: return "Error"
                }
            }
        }
        var sensorRaw: UInt8 = 0
        var stageRaw: UInt8 = 0
        var packets: UInt32? = nil
        var rejected: UInt16? = nil
        /// Ages in deciseconds as sent; nil = field absent or 0xFFFF ("none yet").
        var packetAgeDs: UInt16? = nil
        var validAgeDs: UInt16? = nil
        var lastError: String? = nil
        var seq: UInt16 = 0
        var boardTimeMs: UInt32 = 0
        var sensor: Sensor? { Sensor(rawValue: sensorRaw) }
        var stage: Stage? { Stage(rawValue: stageRaw) }
        var packetAgeS: Double? { packetAgeDs.map { Double($0) / 10 } }
        var validAgeS: Double? { validAgeDs.map { Double($0) / 10 } }
    }
    /// nil for anything that is not a well-formed SENSOR_DIAG (other events, missing sensor or stage, truncated TLV).
    static func decodeSensorDiag(_ d: Data) -> SensorDiag? {
        guard let (h, f) = parse(d), h.type == MsgType.event.rawValue else { return nil }
        var s = SensorDiag(); s.seq = h.seq; s.boardTimeMs = h.tMs
        var isDiag = false, gotSensor = false, gotStage = false
        for x in f {
            let v = x.value
            switch (x.tag, v.count) {
            case (0x01, 1): isDiag = Int(v[v.startIndex]) == sensorDiagEventId
            case (0x02, 1): s.sensorRaw = v[v.startIndex]; gotSensor = true
            case (0x03, 1): s.stageRaw = v[v.startIndex]; gotStage = true
            case (0x04, 4): s.packets = UInt32(uint(v))
            case (0x05, 2): s.rejected = UInt16(uint(v))
            case (0x06, 2): let a = UInt16(uint(v)); s.packetAgeDs = a == 0xFFFF ? nil : a
            case (0x07, 2): let a = UInt16(uint(v)); s.validAgeDs = a == 0xFFFF ? nil : a
            case (0x08, 0...20): s.lastError = v.isEmpty ? nil : String(decoding: v, as: UTF8.self)
            default: break
            }
        }
        return isDiag && gotSensor && gotStage ? s : nil
    }
    /// Test helper mirroring the board's SENSOR_DIAG encoder (same tag order as the spec table).
    static func encodeSensorDiag(_ s: SensorDiag, seq: UInt16, tMs: UInt32) -> Data? {
        var w = Writer(type: .event, seq: seq, tMs: tMs)
        w.u8(0x01, UInt8(sensorDiagEventId)); w.u8(0x02, s.sensorRaw); w.u8(0x03, s.stageRaw)
        if let p = s.packets { w.u32(0x04, p) }
        if let r = s.rejected { w.u16(0x05, r) }
        w.u16(0x06, s.packetAgeDs ?? 0xFFFF); w.u16(0x07, s.validAgeDs ?? 0xFFFF)
        if let e = s.lastError { w.field(0x08, Data(e.utf8.prefix(20))) }
        return w.result
    }
}
