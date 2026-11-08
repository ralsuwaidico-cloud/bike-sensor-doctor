import Foundation

// Cyclift Watch (LILYGO) companion — protocol v1 wire codecs, byte-for-byte mirrors of
// watch/firmware/src/domain/sync.hpp + payloads.hpp (little-endian; absent = 0xFFFF / 0x7FFFFFFF, never zero).
// Pure Swift, unit-tested against vectors produced by the firmware's own encoder (CyWatchWireTests).
enum CyWatchWire {
    static let protocolVersion: UInt8 = 1
    static let absent16: UInt16 = 0xFFFF
    static let absent32: Int32 = 0x7FFF_FFFF
    static let serviceUUID = "6E400001-C1F7-4F1A-9C5E-2026110800C1"
    static let txUUID = "6E400002-C1F7-4F1A-9C5E-2026110800C1"   // watch → phone (notify)
    static let rxUUID = "6E400003-C1F7-4F1A-9C5E-2026110800C1"   // phone → watch (write)

    enum MsgType: UInt8 { case hello = 0x01, timeSync = 0x02, status = 0x03, planToday = 0x10, cached = 0x11, live = 0x20, gps = 0x21, coach = 0x22, event = 0x30, ack = 0x31, error = 0x7F }

    struct Frame: Equatable { var type: MsgType; var seq: UInt16; var payload: [UInt8] }

    // MARK: primitives
    struct Writer {
        var b: [UInt8] = []
        mutating func u8(_ v: UInt8) { b.append(v) }
        mutating func bool(_ v: Bool) { b.append(v ? 1 : 0) }
        mutating func u16(_ v: UInt16) { b.append(UInt8(v & 0xFF)); b.append(UInt8(v >> 8)) }
        mutating func i16(_ v: Int16) { u16(UInt16(bitPattern: v)) }
        mutating func u32(_ v: UInt32) { for i in 0..<4 { b.append(UInt8((v >> (8 * UInt32(i))) & 0xFF)) } }
        mutating func i32(_ v: Int32) { u32(UInt32(bitPattern: v)) }
        mutating func opt16(_ v: UInt16?) { u16(v ?? absent16) }
        mutating func str(_ s: String) { let d = Array(s.utf8.prefix(255)); u8(UInt8(d.count)); b.append(contentsOf: d) }
        mutating func band(_ p: (UInt16, UInt16)?) { u16(p?.0 ?? absent16); u16(p?.1 ?? absent16) }
    }
    struct Reader {
        let b: [UInt8]; var i = 0; var ok = true
        init(_ b: [UInt8]) { self.b = b }
        mutating func u8() -> UInt8 { guard i + 1 <= b.count else { ok = false; return 0 }; defer { i += 1 }; return b[i] }
        mutating func u16() -> UInt16 { guard i + 2 <= b.count else { ok = false; return 0 }; let v = UInt16(b[i]) | UInt16(b[i + 1]) << 8; i += 2; return v }
        mutating func i16() -> Int16 { Int16(bitPattern: u16()) }
        mutating func u32() -> UInt32 { guard i + 4 <= b.count else { ok = false; return 0 }; var v: UInt32 = 0; for k in 0..<4 { v |= UInt32(b[i + k]) << (8 * UInt32(k)) }; i += 4; return v }
        mutating func i32() -> Int32 { Int32(bitPattern: u32()) }
        mutating func opt16() -> UInt16? { let v = u16(); return v == absent16 ? nil : v }
        mutating func str() -> String { let n = Int(u8()); guard i + n <= b.count else { ok = false; return "" }; defer { i += n }; return String(decoding: b[i..<i + n], as: UTF8.self) }
    }

    // MARK: framing  [ver][type][seq lo][seq hi][len lo][len hi][payload…][crc lo][crc hi]
    static func crc16(_ d: ArraySlice<UInt8>) -> UInt16 {
        var crc: UInt16 = 0xFFFF
        for x in d { crc ^= UInt16(x) << 8; for _ in 0..<8 { crc = (crc & 0x8000) != 0 ? (crc << 1) ^ 0x1021 : crc << 1 } }
        return crc
    }
    static func encode(_ f: Frame) -> [UInt8] {
        var w = Writer(); w.u8(protocolVersion); w.u8(f.type.rawValue); w.u16(f.seq); w.u16(UInt16(min(f.payload.count, 0xFFFF))); w.b.append(contentsOf: f.payload)
        let c = crc16(w.b[...]); w.u16(c); return w.b
    }
    static func decode(_ b: [UInt8]) -> Frame? {
        guard b.count >= 8 else { return nil }
        let len = Int(b[4]) | Int(b[5]) << 8
        guard b.count == len + 8, b[0] == protocolVersion else { return nil }
        let c = UInt16(b[b.count - 2]) | UInt16(b[b.count - 1]) << 8
        guard crc16(b[0..<(b.count - 2)]) == c, let t = MsgType(rawValue: b[1]) else { return nil }
        return Frame(type: t, seq: UInt16(b[2]) | UInt16(b[3]) << 8, payload: Array(b[6..<(b.count - 2)]))
    }

    // MARK: 0x20 Live (phone → watch)
    struct Live: Equatable {
        var powerW: UInt16?, hrBpm: UInt16?, cadenceRpm: UInt16?, speedKmh10: UInt16?
        var powerAgeMs: UInt16 = absent16, hrAgeMs: UInt16 = absent16, cadenceAgeMs: UInt16 = absent16, speedAgeMs: UInt16 = absent16
        var ftpKnown = false, ftpW: UInt16 = 0
        var powerBandW: (UInt16, UInt16)?, hrBandBpm: (UInt16, UInt16)?, cadenceRange: (UInt16, UInt16)?
        var stepName = "", stepRemainingS: UInt16 = 0, stepTotalS: UInt16 = 0
        var recording = false, paused = false, elapsedS: UInt32 = 0, distanceM: UInt32 = 0
        func encode() -> [UInt8] {
            var w = Writer()
            w.opt16(powerW); w.u16(powerAgeMs); w.opt16(hrBpm); w.u16(hrAgeMs); w.opt16(cadenceRpm); w.u16(cadenceAgeMs); w.opt16(speedKmh10); w.u16(speedAgeMs)
            w.bool(ftpKnown); w.u16(ftpW); w.band(powerBandW); w.band(hrBandBpm); w.band(cadenceRange)
            w.str(stepName); w.u16(stepRemainingS); w.u16(stepTotalS)
            w.u8((recording ? 1 : 0) | (paused ? 2 : 0)); w.u32(elapsedS); w.u32(distanceM); return w.b
        }
        static func == (a: Live, b: Live) -> Bool { a.encode() == b.encode() }
    }
    // MARK: 0x21 Gps
    struct Gps: Equatable {
        var latE7: Int32, lonE7: Int32, speedKmh10: UInt16, headingDeg: UInt16, phoneUnixS: UInt32, ageMs: UInt16
        func encode() -> [UInt8] { var w = Writer(); w.i32(latE7); w.i32(lonE7); w.u16(speedKmh10); w.u16(headingDeg); w.u32(phoneUnixS); w.u16(ageMs); return w.b }
        init(latE7: Int32, lonE7: Int32, speedKmh10: UInt16, headingDeg: UInt16, phoneUnixS: UInt32, ageMs: UInt16) { self.latE7 = latE7; self.lonE7 = lonE7; self.speedKmh10 = speedKmh10; self.headingDeg = headingDeg; self.phoneUnixS = phoneUnixS; self.ageMs = ageMs }
        init(lat: Double, lon: Double, speedKmh: Double, headingDeg: Double, at: Date, ageMs: Int) {
            self.init(latE7: Int32((lat * 1e7).rounded()), lonE7: Int32((lon * 1e7).rounded()), speedKmh10: UInt16(max(0, min(65_534, (speedKmh * 10).rounded()))),
                      headingDeg: UInt16(max(0, min(359, headingDeg.rounded()))), phoneUnixS: UInt32(max(0, at.timeIntervalSince1970)), ageMs: UInt16(max(0, min(65_534, ageMs))))
        }
    }
    // MARK: 0x02 TimeSync
    struct TimeSync: Equatable {
        var unixS: UInt32, ms: UInt16, tzOffsetMin: Int16
        init(unixS: UInt32, ms: UInt16, tzOffsetMin: Int16) { self.unixS = unixS; self.ms = ms; self.tzOffsetMin = tzOffsetMin }
        init(_ d: Date, timeZone tz: TimeZone = .current) { let t = d.timeIntervalSince1970; self.init(unixS: UInt32(t), ms: UInt16((t - floor(t)) * 1000), tzOffsetMin: Int16(tz.secondsFromGMT(for: d) / 60)) }
        func encode() -> [UInt8] { var w = Writer(); w.u32(unixS); w.u16(ms); w.i16(tzOffsetMin); return w.b }
    }
    // MARK: 0x03 Status (watch → phone)
    struct Status: Equatable {
        var batteryPct: UInt8, charging: Bool, freeHeap: UInt32, phase: UInt8, pendingEvents: UInt32
        static func decode(_ p: [UInt8]) -> Status? { var r = Reader(p); let s = Status(batteryPct: r.u8(), charging: r.u8() != 0, freeHeap: r.u32(), phase: r.u8(), pendingEvents: r.u32()); return r.ok ? s : nil }
    }
    // MARK: 0x22 Coach
    struct Coach: Equatable {
        var id: UInt32; var priority: UInt8; var context: UInt8; var requiresAction: Bool; var safety: Bool; var expiresInS: UInt16; var instruction: String; var reason: String; var target: String
        func encode() -> [UInt8] { var w = Writer(); w.u32(id); w.u8(priority); w.u8(context); w.u8((requiresAction ? 1 : 0) | (safety ? 2 : 0)); w.u16(expiresInS); w.str(instruction); w.str(reason); w.str(target); return w.b }
    }
    // MARK: 0x10 PlanToday
    struct PlanToday: Equatable {
        struct Exercise: Equatable { var id: String; var name: String; var sets: UInt8; var reps: UInt8; var weightKg10: UInt16; var restS: UInt16; var superset: UInt8 }
        /// 0 none, 1 ride, 2 strength
        var kind: UInt8; var workoutId: String; var title: String; var startMin: UInt16; var durationMin: UInt16; var exercises: [Exercise]
        func encode() -> [UInt8] {
            var w = Writer(); w.u8(kind); w.str(workoutId); w.str(title); w.u16(startMin); w.u16(durationMin); w.u8(UInt8(min(exercises.count, 255)))
            for e in exercises.prefix(255) { w.str(e.id); w.str(e.name); w.u8(e.sets); w.u8(e.reps); w.u16(e.weightKg10); w.u16(e.restS); w.u8(e.superset) }
            return w.b
        }
    }
    // MARK: 0x11 Cached (recovery summaries with source + timestamp; absent stays absent)
    struct Cached: Equatable {
        var sleepMin: UInt16?; var sleepSource: String; var sleepUnixS: UInt32; var hrvMs: UInt16?; var hrvUnixS: UInt32; var recoveryPct: UInt8?; var recoveryWord: String; var insight: String; var loadPct: UInt8
        func encode() -> [UInt8] { var w = Writer(); w.opt16(sleepMin); w.str(sleepSource); w.u32(sleepUnixS); w.opt16(hrvMs); w.u32(hrvUnixS); w.u8(recoveryPct ?? 255); w.str(recoveryWord); w.str(insight); w.u8(loadPct); return w.b }
    }
    // MARK: 0x30 Event (watch → phone)
    struct Event: Equatable {
        enum Kind: UInt8 { case start = 1, pause = 2, resume = 3, end = 4, lap = 5, setLogged = 6, repCount = 7, discard = 8, save = 9 }
        var deviceId: String; var seq: UInt32; var watchUnixS: UInt32; var kindRaw: UInt8; var workoutId: String; var a: Int32; var b: Int32; var c: Int32; var manual: Bool
        var kind: Kind? { Kind(rawValue: kindRaw) }
        static func decode(_ p: [UInt8]) -> Event? {
            var r = Reader(p)
            let e = Event(deviceId: r.str(), seq: r.u32(), watchUnixS: r.u32(), kindRaw: r.u8(), workoutId: r.str(), a: r.i32(), b: r.i32(), c: r.i32(), manual: r.u8() != 0)
            return r.ok ? e : nil
        }
    }
    // MARK: 0x31 Ack (cumulative)
    static func encodeAck(_ upTo: UInt32) -> [UInt8] { var w = Writer(); w.u32(upTo); return w.b }
}
